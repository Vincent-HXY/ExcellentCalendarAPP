FROM eclipse-temurin:21-jdk AS build
WORKDIR /workspace

COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN chmod +x mvnw

COPY src/ src/
RUN --mount=type=cache,id=excellent-calendar-maven,target=/root/.m2,sharing=locked \
    for attempt in 1 2 3; do \
      ./mvnw --batch-mode --no-transfer-progress --update-snapshots -Dmaven.test.skip=true package && exit 0; \
      test "$attempt" -lt 3 || exit 1; \
      echo "Maven package download interrupted; retrying with the persistent cache (attempt $((attempt + 1))/3)"; \
    done

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/target/cloud-backend-*.jar /app/cloud-backend.jar

USER 10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/cloud-backend.jar"]
