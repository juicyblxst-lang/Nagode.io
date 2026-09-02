package io.nagode.service;

import jakarta.servlet.*;import jakarta.servlet.http.*;import org.springframework.core.env.Environment;import org.springframework.stereotype.Component;import org.springframework.web.filter.OncePerRequestFilter;import java.io.IOException;

@Component public class ApiKeyFilter extends OncePerRequestFilter {
  private final Environment env; public ApiKeyFilter(Environment env){this.env=env;}
  @Override protected void doFilterInternal(HttpServletRequest req,HttpServletResponse res,FilterChain chain)throws ServletException,IOException{String configured=env.getProperty("nagode.api-key","");if(configured.isBlank()){chain.doFilter(req,res);return;}String path=req.getRequestURI();if(path.startsWith("/api/v1/auth/")||path.equals("/api/v1/webhooks/psp")||path.startsWith("/actuator/")){chain.doFilter(req,res);return;}if(!java.security.MessageDigest.isEqual(configured.getBytes(),OptionalString.value(req.getHeader("X-API-Key")).getBytes())){res.setStatus(401);res.setContentType("application/json");res.getWriter().write("{\"error\":\"INVALID_API_KEY\"}");return;}chain.doFilter(req,res);}
  static final class OptionalString{static String value(String s){return s==null?"":s;}}
}
