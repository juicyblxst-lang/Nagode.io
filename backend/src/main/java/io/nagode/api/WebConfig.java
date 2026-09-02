package io.nagode.api;

import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {
  private final Environment env; public WebConfig(Environment env){this.env=env;}
  @Override public void addCorsMappings(CorsRegistry r){r.addMapping("/api/**").allowedOrigins(env.getProperty("nagode.cors-allowed-origins","http://localhost:3000").split(",")).allowedMethods("GET","POST","PUT","PATCH","DELETE","OPTIONS").allowedHeaders("*").allowCredentials(true).maxAge(3600);}
}
