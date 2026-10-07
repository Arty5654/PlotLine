package com.plotline.backend;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;

import com.plotline.backend.testsupport.InMemoryS3Client;

import software.amazon.awssdk.services.s3.S3Client;

@SpringBootTest
@Import(BackendApplicationTests.InMemoryStorage.class)
class BackendApplicationTests {

	// startup copies old S3 files into the database, so keep it away from real AWS
	@TestConfiguration
	static class InMemoryStorage {
		@Bean
		@Primary
		S3Client inMemoryS3() {
			return new InMemoryS3Client();
		}
	}

	@Test
	void contextLoads() {
	}

}
