package com.plotline.backend.testsupport;

import java.util.Map;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;

/** Points every Spring test context at its own empty test database (see META-INF/spring.factories). */
public class TestDatabaseEnvironment implements EnvironmentPostProcessor {

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        environment.getPropertySources().addFirst(new MapPropertySource("testDatabase",
                Map.of("spring.datasource.url", TestDatabase.newDatabaseUrl())));
    }
}
