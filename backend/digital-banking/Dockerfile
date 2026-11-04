# Kesor Bank backend image (used for Railway; works on any Docker host).
# Build context: backend/digital-banking. Secrets come from the host's environment variables, never from this image.

# Official Maven image (same Maven line as .mvn/wrapper) so the build does not depend on curl/wget for the wrapper.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline
COPY src src
# Tests run before deployment on a workstation (embedded PostgreSQL is too heavy for the image build).
RUN mvn -B -q -DskipTests package && cp target/digital-banking-*.jar app.jar

FROM eclipse-temurin:21-jre-jammy
RUN useradd --system --uid 10001 --create-home kesor
WORKDIR /app
COPY --from=build /workspace/app.jar app.jar
USER kesor
# Business day is Asia/Phnom_Penh; matches the workstation the code was developed on.
ENV TZ=Asia/Phnom_Penh \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=70 -XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError -Xss512k"
EXPOSE 8080
# Railway injects PORT; fall back to SERVER_PORT, then 8080.
ENTRYPOINT ["sh", "-c", "exec java -Dserver.port=${PORT:-${SERVER_PORT:-8080}} -jar /app/app.jar"]
