package com.example.taskflow;

import com.example.taskflow.model.Task;
import com.example.taskflow.model.TaskPriority;
import com.example.taskflow.model.TaskStatus;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.*;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TaskFlowApplicationTests {

    @LocalServerPort
    private int port;

    @Autowired
    private TestRestTemplate restTemplate;

    private String url(String path) {
        return "http://localhost:" + port + path;
    }

    // 1. Application starts successfully (context loads)
    @Test
    void contextLoads() {
        assertThat(restTemplate).isNotNull();
    }

    // 2. GET /health returns HTTP 200
    @Test
    void healthEndpointReturns200() {
        ResponseEntity<Map> response = restTemplate.getForEntity(url("/health"), Map.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).containsEntry("status", "healthy");
    }

    // 3. GET /api/info returns application information
    @Test
    void infoEndpointReturnsAppInfo() {
        ResponseEntity<Map> response = restTemplate.getForEntity(url("/api/info"), Map.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).containsKey("application");
        assertThat(response.getBody()).containsKey("environment");
        assertThat(response.getBody()).containsKey("version");
        assertThat(response.getBody()).containsKey("message");
    }

    // 4. GET /version returns configured version
    @Test
    void versionEndpointReturnsVersion() {
        ResponseEntity<Map> response = restTemplate.getForEntity(url("/version"), Map.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).containsKey("version");
        assertThat(response.getBody()).containsKey("environment");
    }

    // 5. Create task works
    @Test
    void createTaskReturns201() {
        Task task = buildTask("Learn Docker", TaskStatus.TODO, TaskPriority.HIGH);
        ResponseEntity<Task> response = restTemplate.postForEntity(url("/api/tasks"), task, Task.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().getId()).isNotBlank();
        assertThat(response.getBody().getTitle()).isEqualTo("Learn Docker");
    }

    // 6. Get all tasks works
    @Test
    void getAllTasksReturns200() {
        restTemplate.postForEntity(url("/api/tasks"), buildTask("Task A", TaskStatus.TODO, TaskPriority.LOW), Task.class);
        ResponseEntity<Task[]> response = restTemplate.getForEntity(url("/api/tasks"), Task[].class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
    }

    // 7. Get task by ID works
    @Test
    void getTaskByIdReturns200() {
        Task created = restTemplate.postForEntity(url("/api/tasks"), buildTask("Task B", TaskStatus.IN_PROGRESS, TaskPriority.MEDIUM), Task.class).getBody();
        assertThat(created).isNotNull();

        ResponseEntity<Task> response = restTemplate.getForEntity(url("/api/tasks/" + created.getId()), Task.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().getId()).isEqualTo(created.getId());
    }

    // 8. Update task works
    @Test
    void updateTaskReturns200() {
        Task created = restTemplate.postForEntity(url("/api/tasks"), buildTask("Old Title", TaskStatus.TODO, TaskPriority.LOW), Task.class).getBody();
        assertThat(created).isNotNull();

        Task updated = buildTask("New Title", TaskStatus.DONE, TaskPriority.HIGH);
        HttpEntity<Task> request = new HttpEntity<>(updated);
        ResponseEntity<Task> response = restTemplate.exchange(url("/api/tasks/" + created.getId()), HttpMethod.PUT, request, Task.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().getTitle()).isEqualTo("New Title");
        assertThat(response.getBody().getStatus()).isEqualTo(TaskStatus.DONE);
    }

    // 9. Delete task works
    @Test
    void deleteTaskReturns204() {
        Task created = restTemplate.postForEntity(url("/api/tasks"), buildTask("To Delete", TaskStatus.TODO, TaskPriority.LOW), Task.class).getBody();
        assertThat(created).isNotNull();

        ResponseEntity<Void> response = restTemplate.exchange(url("/api/tasks/" + created.getId()), HttpMethod.DELETE, null, Void.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
    }

    // 10. Invalid task ID returns 404
    @Test
    void invalidTaskIdReturns404() {
        ResponseEntity<Map> response = restTemplate.getForEntity(url("/api/tasks/non-existent-id"), Map.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    private Task buildTask(String title, TaskStatus status, TaskPriority priority) {
        Task task = new Task();
        task.setTitle(title);
        task.setDescription("Test description");
        task.setStatus(status);
        task.setPriority(priority);
        return task;
    }
}
