package io.nagode.service;

import io.nagode.domain.Models;
import io.nagode.domain.Models.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service
public class FinancialService {
  private static final UUID PAYER=UUID.fromString("00000000-0000-0000-0000-000000000001");
  private static final UUID MERCHANT=UUID.fromString("00000000-0000-0000-0000-000000000002");
  private static final UUID SUSPENSE=UUID.fromString("00000000-0000-0000-0000-000000000003");
  private final JdbcTemplate db;
  public FinancialService(JdbcTemplate db){this.db=db;}

  public record Payment(UUID id,String merchantId,UUID payerAccount,UUID payeeAccount,long amount,String currency,String status,String pspReference,long version,String createdAt,String updatedAt){}
  public record Wallet(String currency,long availableBalance,long version){}

  @Transactional
  public UUID createPayment(String merchantId,long amount,String currency){
    if(amount<=0) throw new IllegalArgumentException("amount must be positive");
    UUID id=UUID.randomUUID();
    db.update("insert into payments(id,merchant_id,payer_account,payee_account,amount,currency,status) values(?,?,?,?,?,?,?)",id,merchantId,PAYER,MERCHANT,amount,currency,"INITIATED");
    post(LedgerType.PAYMENT,id,List.of(new Posting(PAYER,Direction.DEBIT,amount),new Posting(SUSPENSE,Direction.CREDIT,amount)));
    transition(id,"INITIATED","HELD",null);
    return id;
  }

  @Transactional
  public void authorize(UUID id,String pspReference){
    Payment p=get(id); require(p.status(),"HELD","authorize");
    transition(id,"HELD","AUTHORIZED",pspReference);
  }

  @Transactional
  public void fail(UUID id){
    Payment p=get(id); if(p.status().equals("FAILED")||p.status().equals("REVERSED"))return;
    if(!Set.of("HELD","AUTHORIZED","PENDING").contains(p.status())) throw new IllegalStateException("payment cannot fail from "+p.status());
    post(LedgerType.REVERSAL,id,List.of(new Posting(SUSPENSE,Direction.DEBIT,p.amount()),new Posting(PAYER,Direction.CREDIT,p.amount())));
    transition(id,p.status(),"REVERSED",p.pspReference());
  }

  @Transactional
  public void capture(UUID id){Payment p=get(id);require(p.status(),"AUTHORIZED","capture");transition(id,"AUTHORIZED","PENDING",p.pspReference());}

  @Transactional
  public void settle(UUID id){
    Payment p=get(id);require(p.status(),"PENDING","settle");
    post(LedgerType.PAYMENT,id,List.of(new Posting(SUSPENSE,Direction.DEBIT,p.amount()),new Posting(MERCHANT,Direction.CREDIT,p.amount())));
    transition(id,"PENDING","SETTLED",p.pspReference());
  }

  @Transactional
  public UUID refund(UUID paymentId,long amount){
    Payment p=get(paymentId); if(!p.status().equals("SETTLED"))throw new IllegalStateException("only settled payments can be refunded");
    long refunded=db.queryForObject("select coalesce(sum(amount),0) from refunds where payment_id=? and status='COMPLETED'",Long.class,paymentId);
    if(amount<=0||amount>p.amount()-refunded)throw new IllegalArgumentException("refund exceeds refundable amount");
    UUID refund=UUID.randomUUID();db.update("insert into refunds(id,payment_id,amount,status) values(?,?,?,'PENDING')",refund,paymentId,amount);
    post(LedgerType.REFUND,refund,List.of(new Posting(MERCHANT,Direction.DEBIT,amount),new Posting(PAYER,Direction.CREDIT,amount)));
    db.update("update refunds set status='COMPLETED' where id=?",refund);return refund;
  }

  public Wallet wallet(){return db.queryForObject("select a.currency,b.balance,b.version from accounts a join account_balances b on b.account_id=a.id where a.id=?",(r,n)->new Wallet(r.getString(1),r.getLong(2),r.getLong(3)),PAYER);}
  public Payment get(UUID id){return db.queryForObject("select id,merchant_id,payer_account,payee_account,amount,currency,status,psp_reference,version,created_at,updated_at from payments where id=?",(r,n)->new Payment(UUID.fromString(r.getString(1)),r.getString(2),UUID.fromString(r.getString(3)),UUID.fromString(r.getString(4)),r.getLong(5),r.getString(6),r.getString(7),r.getString(8),r.getLong(9),r.getString(10),r.getString(11)),id);}
  public List<Payment> list(int limit,int offset){return db.query("select id,merchant_id,payer_account,payee_account,amount,currency,status,psp_reference,version,created_at,updated_at from payments order by created_at desc limit ? offset ?",(r,n)->new Payment(UUID.fromString(r.getString(1)),r.getString(2),UUID.fromString(r.getString(3)),UUID.fromString(r.getString(4)),r.getLong(5),r.getString(6),r.getString(7),r.getString(8),r.getLong(9),r.getString(10),r.getString(11)),limit,offset);}
  public List<Map<String,Object>> ledger(UUID id){return db.queryForList("select le.id,le.direction,le.amount,le.created_at,a.type account_type from ledger_entries le join ledger_transactions lt on lt.id=le.transaction_id join accounts a on a.id=le.account_id where lt.reference_id=? order by le.id",id);}
  public List<Map<String,Object>> history(UUID id){return db.queryForList("select status,psp_reference,created_at from payment_status_history where payment_id=? order by id",id);}

  private void require(String actual,String expected,String action){if(!actual.equals(expected))throw new IllegalStateException("cannot "+action+" payment from "+actual);}
  private void transition(UUID id,String from,String to,String psp){int n=db.update("update payments set status=?,psp_reference=coalesce(?,psp_reference),version=version+1,updated_at=now() where id=? and status=?",to,psp,id,from);if(n!=1)throw new IllegalStateException("concurrent or invalid payment transition");db.update("insert into payment_status_history(payment_id,status,psp_reference) values(?,?,?)",id,to,psp);}
  private void post(LedgerType type,UUID ref,List<Posting> p){long d=p.stream().filter(x->x.direction()==Direction.DEBIT).mapToLong(Posting::amount).sum(),c=p.stream().filter(x->x.direction()==Direction.CREDIT).mapToLong(Posting::amount).sum();if(d!=c)throw new IllegalArgumentException("unbalanced ledger");List<UUID> ids=p.stream().map(Posting::accountId).distinct().sorted().toList();for(UUID id:ids)db.queryForObject("select account_id from account_balances where account_id=? for update",UUID.class,id);for(Posting x:p){String typeAccount=db.queryForObject("select type from accounts where id=?",String.class,x.accountId());long sign=typeAccount.equals("USER_WALLET")?(x.direction()==Direction.DEBIT?1:-1):(x.direction()==Direction.CREDIT?1:-1);if(db.queryForObject("select balance from account_balances where account_id=?",Long.class,x.accountId())+sign*x.amount()<0)throw new IllegalStateException("insufficient funds");}UUID tx=UUID.randomUUID();db.update("insert into ledger_transactions(id,type,reference_id) values(?,?,?)",tx,type.name(),ref);for(Posting x:p)db.update("insert into ledger_entries(transaction_id,account_id,direction,amount) values(?,?,?,?)",tx,x.accountId(),x.direction().name(),x.amount());for(Posting x:p){String t=db.queryForObject("select type from accounts where id=?",String.class,x.accountId());long sign=t.equals("USER_WALLET")?(x.direction()==Direction.DEBIT?1:-1):(x.direction()==Direction.CREDIT?1:-1);db.update("update account_balances set balance=balance+?,version=version+1,updated_at=now() where account_id=?",sign*x.amount(),x.accountId());}}
}
