package com.plotline.backend.controller;

import com.plotline.backend.service.OpenAIService;

import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/openai")
public class OpenAIController {
  

  @Autowired
  private OpenAIService openAIService;

  // @Arty5654 @ay-chang @ymehtaa example of post to return json response of string
  @PostMapping("/string-response")
    public Map<String, String> chatWithOpenAI(@RequestBody Map<String, String> request) {
      String userMessage = request.get("message");
      String response = openAIService.generateResponse(userMessage);
      return Map.of("response", response);
  }



  
}
