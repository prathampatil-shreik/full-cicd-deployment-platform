package com.example.taskflow.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

@Configuration
public class ApplicationConfig {

    @Value("${app.env}")
    private String environment;

    @Value("${app.version}")
    private String version;

    @Value("${app.message}")
    private String message;

    public String getEnvironment() { return environment; }
    public String getVersion() { return version; }
    public String getMessage() { return message; }
}
