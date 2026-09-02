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
USER nagode
EXPOSE 8080
ENTRYPOINT ["java","-XX:+UseZGC","-jar","/app/app.jar"]
