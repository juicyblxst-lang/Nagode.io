package io.nagode.api;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class HealthController { @GetMapping("/status") public Object status(){return java.util.Map.of("service","Nagode.io","status","UP");} }
