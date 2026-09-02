package io.nagode.api;

import io.nagode.service.AuthService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.*;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;

@Component
public class AuthFilter extends OncePerRequestFilter {
  private final AuthService auth; public AuthFilter(AuthService auth){this.auth=auth;}
  @Override protected void doFilterInternal(HttpServletRequest req,HttpServletResponse res,FilterChain chain)throws ServletException,IOException{
    String path=req.getRequestURI();if(!path.startsWith("/api/v1/")||path.startsWith("/api/v1/auth/")||path.equals("/api/v1/webhooks/psp")||path.startsWith("/actuator/")){chain.doFilter(req,res);return;}
    String token=null;if(req.getCookies()!=null)for(Cookie c:req.getCookies())if(c.getName().equals("nagode_session"))token=c.getValue();
    var user=auth.current(token);if(user==null){res.setStatus(401);res.setContentType(MediaType.APPLICATION_JSON_VALUE);res.getWriter().write("{\"error\":\"UNAUTHENTICATED\",\"message\":\"authentication required\"}");return;}req.setAttribute("nagode.user",user);chain.doFilter(req,res);
  }
}
