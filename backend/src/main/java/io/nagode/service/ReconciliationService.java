package io.nagode.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import java.util.*;

@Service
public class ReconciliationService {
  private final JdbcTemplate db; private volatile Map<String,Object> last=Map.of("status","NOT_RUN");
  public ReconciliationService(JdbcTemplate db){this.db=db;}
  @Scheduled(cron="0 0 2 * * *",zone="UTC") public void scheduled(){run();}
  public synchronized Map<String,Object> run(){List<Map<String,Object>> mismatches=db.queryForList("select a.id,a.type,a.currency,b.balance,coalesce(sum(case when le.direction='DEBIT' then case when a.type='USER_WALLET' then le.amount else -le.amount end else case when a.type='USER_WALLET' then -le.amount else le.amount end end),0) ledger_balance from accounts a join account_balances b on b.account_id=a.id left join ledger_entries le on le.account_id=a.id group by a.id,a.type,a.currency,b.balance");long count=mismatches.stream().filter(r->!Objects.equals(((Number)r.get("balance")).longValue(),((Number)r.get("ledger_balance")).longValue())).count();Long imbalance=db.queryForObject("select coalesce(sum(case when direction='DEBIT' then amount else -amount end),0) from ledger_entries",Long.class);last=Map.of("status",count==0&&imbalance==0?"HEALTHY":"DISCREPANCY","checkedAt",new Date().toString(),"accountMismatches",count,"ledgerImbalance",imbalance==null?0:imbalance);return last;}
  public Map<String,Object> last(){return last;}
}
