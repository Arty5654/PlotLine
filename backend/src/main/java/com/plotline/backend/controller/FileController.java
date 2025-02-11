package com.plotline.backend.controller;

import com.plotline.backend.service.S3Service;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;

@RestController
@RequestMapping("/api/files")
public class FileController {

  private final S3Service s3Service;

  @Autowired
  public FileController(S3Service s3Service) {
    this.s3Service = s3Service;
  }

  @PostMapping("/upload")
  public ResponseEntity<String> uploadFile(@RequestParam("file") MultipartFile file) throws IOException {
    s3Service.uploadFile(file.getOriginalFilename(), file.getInputStream(), file.getSize());
    return ResponseEntity.ok("File uploaded successfully");
  }

  @GetMapping("/download/{fileName}")
  public ResponseEntity<byte[]> downloadFile(@PathVariable String fileName) {
    byte[] fileData = s3Service.downloadFile(fileName);
    HttpHeaders headers = new HttpHeaders();
    headers.add(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=" + fileName);
    return new ResponseEntity<>(fileData, headers, HttpStatus.OK);
  }

  @DeleteMapping("/delete/{fileName}")
  public ResponseEntity<String> deleteFile(@PathVariable String fileName) {
    s3Service.deleteFile(fileName);
    return ResponseEntity.ok("File deleted successfully");
  }
}
