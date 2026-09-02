package io.nagode;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class NagodeApplication {
  public static void main(String[] args) {
    normalizeRenderPostgresUrl();
    SpringApplication.run(NagodeApplication.class, args);
  }

  /**
   * Render exposes a Postgres connection string as postgres:// or postgresql://.
   * Hikari/PostgreSQL JDBC requires jdbc:postgresql://. Normalize only these
   * schemes and leave an already-correct JDBC URL untouched.
   */
  private static void normalizeRenderPostgresUrl() {
    String url = System.getenv("SPRING_DATASOURCE_URL");
    if (url == null || url.isBlank()) {
      return;
    }

    String normalized = url;
    if (url.startsWith("postgres://")) {
      normalized = "jdbc:postgresql://" + url.substring("postgres://".length());
    } else if (url.startsWith("postgresql://")) {
      normalized = "jdbc:postgresql://" + url.substring("postgresql://".length());
    }

    if (!normalized.equals(url)) {
      System.setProperty("spring.datasource.url", normalized);
    }
  }
}
