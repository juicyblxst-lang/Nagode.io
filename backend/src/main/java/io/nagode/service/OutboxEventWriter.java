package io.nagode.service;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.stereotype.Service;import java.util.*;
@Service public class OutboxEventWriter {private final JdbcTemplate db;public OutboxEventWriter(JdbcTemplate db){this.db=db;}public void write(String type,UUID aggregate,Object payload){db.update("insert into outbox(id,aggregate_type,aggregate_id,event_type,payload) values(?, 'PAYMENT', ?, ?, ?::jsonb)",UUID.randomUUID(),aggregate,type,String.valueOf(payload));}}
