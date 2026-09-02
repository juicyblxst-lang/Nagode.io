package io.nagode.service;

import io.nagode.domain.Models.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service public class UserPaymentService {
  private final JdbcTemplate db; public UserPaymentService(JdbcTemplate db){this.db=db;}
  private static final UUID MERCHANT=UUID.fromString("00000000-0000-0000-0000-000000000002"),SUSPENSE=UUID.fromString("00000000-0000-0000-0000-000000000003");
  @Transactional public UUID create(UUID payer,String merchant,long amount,String currency){if(amount<=0)throw new IllegalArgumentException("amount must be positive");UUID id=UUID.randomUUID();db.update("insert into payments(id,merchant_id,payer_account,payee_account,amount,currency,status) values(?,?,?,?,?,?,?)",id,merchant,payer,MERCHANT,amount,currency,"INITIATED");post(id,payer,amount);transition(id,"INITIATED","HELD");return id;}
  private void post(UUID ref,UUID payer,long amount){for(UUID id:List.of(payer,SUSPENSE).stream().sorted().toList())db.queryForObject("select account_id from account_balances where account_id=? for update",UUID.class,id);Long balance=db.queryForObject("select balance from account_balances where account_id=?",Long.class,payer);if(balance==null||balance<amount)throw new IllegalStateException("insufficient funds");UUID tx=UUID.randomUUID();db.update("insert into ledger_transactions(id,type,reference_id) values(?, 'PAYMENT', ?)",tx,ref);db.update("insert into ledger_entries(transaction_id,account_id,direction,amount) values(?,?, 'DEBIT',?)",tx,payer,amount);db.update("insert into ledger_entries(transaction_id,account_id,direction,amount) values(?,?, 'CREDIT',?)",tx,SUSPENSE,amount);db.update("update account_balances set balance=balance-?,version=version+1,updated_at=now() where account_id=?",amount,payer);db.update("update account_balances set balance=balance+?,version=version+1,updated_at=now() where account_id=?",amount,SUSPENSE);}
  private void transition(UUID id,String from,String to){if(!PaymentRules.validTransition(from,to))throw new IllegalStateException("invalid payment transition");int n=db.update("update payments set status=?,version=version+1,updated_at=now() where id=? and status=?",to,id,from);if(n!=1)throw new IllegalStateException("invalid concurrent transition");db.update("insert into payment_status_history(payment_id,status) values(?,?)",id,to);}
}
