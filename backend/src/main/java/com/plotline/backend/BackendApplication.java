package com.plotline.backend;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import io.github.cdimascio.dotenv.Dotenv;
//import org.springframework.context.annotation.ComponentScan;

@SpringBootApplication
//@ComponentScan(basePackages = {"com.plotline.backend"})
public class BackendApplication {

	public static void main(String[] args) {
		// local runs keep secrets in .env; Spring only reads real environment variables
		if (System.getenv("DATABASE_URL") == null) {
			String databaseUrl = Dotenv.configure().ignoreIfMissing().load().get("DATABASE_URL");
			if (databaseUrl != null) System.setProperty("DATABASE_URL", databaseUrl);
		}
		SpringApplication.run(BackendApplication.class, args);
	}

}
