FROM maven:3.9.11-eclipse-temurin-21-alpine AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q clean package -DskipTests

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S nagode && adduser -S nagode -G nagode
WORKDIR /app
COPY --from=build /build/target/nagode-backend-1.0.0.jar app.jar
COPY docker-entrypoint.sh /usr/local/bin/nagode-entrypoint
RUN chmod 0555 /usr/local/bin/nagode-entrypoint
USER nagode
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/nagode-entrypoint"]
CMD ["java","-XX:+UseZGC","-jar","/app/app.jar"]
