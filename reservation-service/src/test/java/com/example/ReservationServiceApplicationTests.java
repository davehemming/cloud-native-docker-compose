package com.example;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.junit4.SpringRunner;

import static org.assertj.core.api.Assertions.assertThat;

@RunWith(SpringRunner.class)
@SpringBootTest
public class ReservationServiceApplicationTests {

	@Test
	public void contextLoads() {
	}

	@Test public void helloWorldTest() {

		assertThat("Hello World fail").isEqualTo("Hello World");
	}

}
