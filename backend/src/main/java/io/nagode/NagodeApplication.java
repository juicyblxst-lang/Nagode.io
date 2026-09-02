package io.nagode;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class NagodeApplication {
  public static void main(String[] args) {
    SpringApplication.run(NagodeApplication.class, args);
  }
}
