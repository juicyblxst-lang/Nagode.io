package io.nagode.api;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/internal") public class TestEndpoint { @GetMapping("/ping") public String ping(){return "pong";} }
