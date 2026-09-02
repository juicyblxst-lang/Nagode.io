package io.nagode.service;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.scheduling.annotation.Scheduled;import org.springframework.stereotype.Service;
@Service public class SessionCleanup {private final JdbcTemplate db;public SessionCleanup(JdbcTemplate db){this.db=db;}@Scheduled(cron="0 15 * * * *") public void clean(){db.update("delete from sessions where expires_at<now()");}}
