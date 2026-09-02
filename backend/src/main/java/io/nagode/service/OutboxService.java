package io.nagode.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service
public class OutboxService {
  private final JdbcTemplate db; public OutboxService(JdbcTemplate db){this.db=db;}
  @Scheduled(fixedDelay=5000)
  public void publish(){List<Map<String,Object>> events=claim();for(var e:events){try{System.out.println("NAGODE_OUTBOX event="+e.get("event_type")+" aggregate="+e.get("aggregate_id"));db.update("update outbox set published_at=now(),attempts=attempts+1,last_error=null where id=?",e.get("id"));}catch(Exception ex){db.update("update outbox set attempts=attempts+1,last_error=? where id=?",safe(ex),e.get("id"));}}}
  @Transactional public List<Map<String,Object>> claim(){return db.queryForList("select id,aggregate_id,event_type,payload from outbox where published_at is null order by created_at limit 50");}
  public long depth(){Long n=db.queryForObject("select count(*) from outbox where published_at is null",Long.class);return n==null?0:n;}
  private String safe(Exception e){return e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage()).substring(0,Math.min(200,String.valueOf(e.getMessage()).length()));}
}
