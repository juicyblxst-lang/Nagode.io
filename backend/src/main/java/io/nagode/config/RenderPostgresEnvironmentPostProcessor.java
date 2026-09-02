package io.nagode.config;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;

import java.util.Map;

/**
 * Render database connection strings use postgres:// or postgresql://,
 * while Spring Boot's JDBC datasource requires jdbc:postgresql://.
 * Normalize the value before Spring Boot binds DataSourceProperties so the
 * environment variable cannot override the normalized system property.
 */
public final class RenderPostgresEnvironmentPostProcessor implements EnvironmentPostProcessor {
  private static final String KEY = "SPRING_DATASOURCE_URL";
  private static final String PROPERTY = "spring.datasource.url";

  @Override
  public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
    String url = environment.getProperty(KEY);
    if (url == null || url.isBlank()) {
      return;
    }

    String normalized = normalize(url);
    if (!normalized.equals(url)) {
      environment.getPropertySources().addFirst(
          new MapPropertySource("nagode-render-jdbc-normalization", Map.of(PROPERTY, normalized)));
    }
  }

  static String normalize(String url) {
    if (url.startsWith("postgres://")) {
      return "jdbc:postgresql://" + url.substring("postgres://".length());
    }
    if (url.startsWith("postgresql://")) {
      return "jdbc:postgresql://" + url.substring("postgresql://".length());
    }
    return url;
  }
}
