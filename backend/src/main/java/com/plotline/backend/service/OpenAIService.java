package com.plotline.backend.service;


import com.openai.client.OpenAIClient;
import com.openai.client.okhttp.OpenAIOkHttpClient;
import com.openai.errors.OpenAIException;
import com.openai.models.ChatCompletion;
import com.openai.models.ChatCompletionCreateParams;
import com.openai.models.ChatModel;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;

import io.github.cdimascio.dotenv.Dotenv;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class OpenAIService {

  private final OpenAIClient openAIClient;

  public OpenAIService() {

    Dotenv dotenv = Dotenv.load();
    String openaiApiKey = dotenv.get("OPENAI_API_KEY");

    this.openAIClient = OpenAIOkHttpClient.builder()
                        .apiKey(openaiApiKey)
                        .build(); 

  }

  // @Arty5654 @ay-chang @ymehtaa this is an example which sends a user prompt and returns the response
  public String generateResponse(String userMessage) {

    try {

      /*
       * Key:
       * System message: These are instructions to the model to tell it how to act
       * User message: This is the prompt to get answered
       * Model: Try to only use 4o mini unless it gives context window errors
       * Response Format: probably use json and force it to create a list/map for objectMapper parsing
       *  -> if you want to output a list (ie. yash grocery list), add that into system message and ensure the response is an array of objects with the needed fields 
       *  -> define the objects you need as DTO classes and then use ObjectMapper to parse back
       */

      String systemMessage = "You are a helpful assistant. You must ALWAYS respond with a single string of text. If multiple paragraphs are needed, break them up with a single newline character";

      ChatCompletionCreateParams params = ChatCompletionCreateParams.builder()
        .addSystemMessage(systemMessage)
        .addUserMessage(userMessage)
        .model(ChatModel.GPT_4O_MINI)
        .build();

      ChatCompletion chatCompletion = openAIClient.chat().completions().create(params);

      return chatCompletion.choices().get(0).message().content().orElse("Service Error");

    } catch (OpenAIException e) {
      // error handling and types of errors found in SDK readme

      e.printStackTrace();
      return "Service Error";
    }

  } 
  
}
