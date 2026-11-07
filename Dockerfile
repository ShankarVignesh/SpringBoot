FROM amazoncorretto:25.0.5-alpine3.23
ARG JAR_FILE=target/*.jar
COPY ${JAR_FILE} container.jar
ENTRYPOINT ["java","-jar","/container.jar"]