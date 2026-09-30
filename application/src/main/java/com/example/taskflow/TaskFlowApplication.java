package com.example.taskflow;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;

@SpringBootApplication
public class TaskFlowApplication {

    private static final Logger log = LoggerFactory.getLogger(TaskFlowApplication.class);

    public static void main(String[] args) {
        SpringApplication.run(TaskFlowApplication.class, args);
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onStartup() {
        log.info("TaskFlow - Task Management System started successfully");
    }
}
