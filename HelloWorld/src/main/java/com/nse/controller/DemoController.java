package com.nse.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DemoController {

	@GetMapping("/get")
	public String getData(@RequestParam("name") String name) {
		System.out.println("Name : "+name+" !");
		return "Hello! "+name;
	}
}
