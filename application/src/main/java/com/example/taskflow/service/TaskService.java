package com.example.taskflow.service;

import com.example.taskflow.exception.TaskNotFoundException;
import com.example.taskflow.model.Task;
import com.example.taskflow.model.TaskStatus;
import com.example.taskflow.repository.TaskRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class TaskService {

    private static final Logger log = LoggerFactory.getLogger(TaskService.class);

    private final TaskRepository repo;

    public TaskService(TaskRepository repo) {
        this.repo = repo;
    }

    public Task create(Task task) {
        Task saved = repo.save(new Task(task.getTitle(), task.getDescription(), task.getStatus(), task.getPriority()));
        log.info("Task created: id={}, title={}", saved.getId(), saved.getTitle());
        return saved;
    }

    public List<Task> findAll() {
        return repo.findAll();
    }

    public Task findById(String id) {
        return repo.findById(id).orElseThrow(() -> new TaskNotFoundException(id));
    }

    public Task update(String id, Task updated) {
        Task existing = findById(id);
        existing.setTitle(updated.getTitle());
        existing.setDescription(updated.getDescription());
        existing.setStatus(updated.getStatus());
        existing.setPriority(updated.getPriority());
        Task saved = repo.save(existing);
        log.info("Task updated: id={}", id);
        return saved;
    }

    public void delete(String id) {
        findById(id);
        repo.deleteById(id);
        log.info("Task deleted: id={}", id);
    }

    public Task updateStatus(String id, TaskStatus status) {
        Task task = findById(id);
        task.setStatus(status);
        Task saved = repo.save(task);
        log.info("Task status updated: id={}, status={}", id, status);
        return saved;
    }
}
