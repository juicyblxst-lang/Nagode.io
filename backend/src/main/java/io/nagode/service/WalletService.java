package io.nagode.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import java.util.*;

@Service
public class WalletService {
  private final JdbcTemplate db;
  public WalletService(JdbcTemplate db){this.db=db;}
  public Map<String,Object> wallet(UUID userId){return db.queryForMap("select a.id account_id,a.currency,b.balance,b.version,b.updated_at from accounts a join account_balances b on b.account_id=a.id where a.owner_type='USER' and a.owner_id=? and a.type='USER_WALLET'",userId.toString());}
}
