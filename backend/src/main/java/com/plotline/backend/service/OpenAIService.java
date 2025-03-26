package com.plotline.backend.service;


import com.openai.client.OpenAIClient;
import com.openai.client.okhttp.OpenAIOkHttpClient;
import com.openai.errors.OpenAIException;
import com.openai.models.ChatModel;

import com.openai.models.responses.Response;
import com.openai.models.responses.ResponseCreateParams;
import com.openai.models.responses.ResponseOutputItem;
import com.openai.models.responses.ResponseOutputMessage;
import com.openai.models.responses.ResponseOutputText;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonMappingException;
import com.fasterxml.jackson.databind.JsonNode;

import io.github.cdimascio.dotenv.Dotenv;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class OpenAIService {

  private final OpenAIClient openAIClient;
  private final ObjectMapper objectMapper = new ObjectMapper();

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

      ResponseCreateParams params = ResponseCreateParams.builder()
        .input(userMessage)
        .instructions(systemMessage)
        .model(ChatModel.GPT_4O_MINI)
        .build();

        Response response = openAIClient.responses().create(params);

        ResponseOutputText rot = response.output().get(0).message().get().content().get(0).asOutputText();
        String output = rot.text();

      //System.out.println("OpenAI response:\n" + result);

      return output;

    } catch (OpenAIException e) {
      // error handling and types of errors found in SDK readme

      e.printStackTrace();
      return "Service Error";
    }

  }

  // Response for Estimating Groccery Costs
  public String generateResponseGC(String userMessage) {

    try {
        String systemMessage = "You are a helpful financial assistant." +
        "Respond with ONLY a single plain text number rounded to 2 decimals (e.g., 15.75) with no extra characters, punctuation, " +
        "or JSON formatting. Do not wrap your answer in braces or quotes.";
        ResponseCreateParams params = ResponseCreateParams.builder()
            .input(userMessage)
            .instructions(systemMessage)
            .model(ChatModel.GPT_4O_MINI)
            .build();

        Response response = openAIClient.responses().create(params);
        ResponseOutputText rot = response.output().get(0).message().get().content().get(0).asOutputText();
        String output = rot.text();

        System.out.println("OpenAI response: " + output);
        return output;

    } catch (OpenAIException e) {
      // error handling and types of errors found in SDK readme

      e.printStackTrace();
      return "Service Error";
    }

  } 
  
}
