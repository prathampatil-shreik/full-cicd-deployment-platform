package com.example.taskflow.controller;

import com.example.taskflow.config.ApplicationConfig;
import com.example.taskflow.repository.TaskRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class ApplicationController {

    private static final Logger log = LoggerFactory.getLogger(ApplicationController.class);

    private final ApplicationConfig config;
    private final TaskRepository taskRepository;

    public ApplicationController(ApplicationConfig config, TaskRepository taskRepository) {
        this.config = config;
        this.taskRepository = taskRepository;
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        try {
            taskRepository.count();
            log.debug("Health check passed");
            return ResponseEntity.ok(Map.of("status", "healthy"));
        } catch (Exception e) {
            log.error("Health check failed: {}", e.getMessage());
            return ResponseEntity.status(503).body(Map.of("status", "unhealthy", "error", e.getMessage()));
        }
    }

    @GetMapping("/api/info")
    public ResponseEntity<Map<String, String>> info() {
        return ResponseEntity.ok(Map.of(
                "application", "TaskFlow - Task Management System",
                "environment", config.getEnvironment(),
                "version", config.getVersion(),
                "message", config.getMessage()
        ));
    }

    @GetMapping("/version")
    public ResponseEntity<Map<String, String>> version() {
        return ResponseEntity.ok(Map.of(
                "application", "TaskFlow",
                "environment", config.getEnvironment(),
                "version", config.getVersion()
        ));
    }
}
