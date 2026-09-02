package io.nagode.api;

import io.nagode.service.AuthService;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
  private final AuthService auth; public AuthController(AuthService auth){this.auth=auth;}
  public record Register(@Email @NotBlank String email,@NotBlank String password,@NotBlank String displayName){}
  public record Login(@Email @NotBlank String email,@NotBlank String password){}
  @PostMapping("/register") public Object register(@Valid @RequestBody Register r){return auth.register(r.email(),r.password(),r.displayName());}
  @PostMapping("/login") public Object login(@Valid @RequestBody Login r,HttpServletResponse response){var s=auth.login(r.email(),r.password());Cookie c=new Cookie("nagode_session",s.token());c.setHttpOnly(true);c.setSecure(true);c.setPath("/");c.setMaxAge(7*24*60*60);response.addCookie(c);return auth.current(s.token());}
  @PostMapping("/logout") public ResponseEntity<Void> logout(@CookieValue(value="nagode_session",required=false) String token,HttpServletResponse response){auth.logout(token);Cookie c=new Cookie("nagode_session","");c.setHttpOnly(true);c.setSecure(true);c.setPath("/");c.setMaxAge(0);response.addCookie(c);return ResponseEntity.noContent().build();}
  @GetMapping("/me") public Object me(@CookieValue(value="nagode_session",required=false) String token){var u=auth.current(token);if(u==null)return ResponseEntity.status(401).build();return u;}
}
