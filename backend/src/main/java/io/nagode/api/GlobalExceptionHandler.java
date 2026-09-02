package io.nagode.api;
import org.springframework.http.*;import org.springframework.web.bind.MethodArgumentNotValidException;import org.springframework.web.bind.annotation.*;import java.util.*;
@RestControllerAdvice public class GlobalExceptionHandler {
 @ExceptionHandler(MethodArgumentNotValidException.class) ResponseEntity<?> validation(MethodArgumentNotValidException e){return body(422,"VALIDATION_ERROR","request validation failed");}
 @ExceptionHandler(org.springframework.web.server.ResponseStatusException.class) ResponseEntity<?> status(org.springframework.web.server.ResponseStatusException e){return body(e.getStatusCode().value(),"REQUEST_REJECTED",e.getReason()==null?"request rejected":e.getReason());}
 @ExceptionHandler(IllegalArgumentException.class) ResponseEntity<?> bad(IllegalArgumentException e){return body(422,"INVALID_REQUEST",e.getMessage());}
 @ExceptionHandler(Exception.class) ResponseEntity<?> unexpected(Exception e){return body(500,"INTERNAL_ERROR","request could not be completed");}
 private ResponseEntity<?> body(int code,String error,String message){return ResponseEntity.status(code).contentType(MediaType.APPLICATION_JSON).body(Map.of("error",error,"message",message));}
}
