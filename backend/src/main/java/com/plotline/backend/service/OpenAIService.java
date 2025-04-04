package com.plotline.backend.service;


import com.openai.client.OpenAIClient;
import com.openai.client.okhttp.OpenAIOkHttpClient;
import com.openai.errors.OpenAIException;
import com.openai.models.ChatModel;

import com.openai.models.responses.Response;
import com.openai.models.responses.ResponseCreateParams;
import com.openai.models.responses.ResponseOutputText;
import com.plotline.backend.dto.DietaryRestrictions;
import com.fasterxml.jackson.databind.ObjectMapper;

import io.github.cdimascio.dotenv.Dotenv;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class OpenAIService {

  private final OpenAIClient openAIClient;
  private final ObjectMapper objectMapper = new ObjectMapper();

  @Autowired
    private DietaryRestrictionsService dietaryRestrictionsService;

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

    public String generateResponsePortfolio(String userMessage) {
      try {
          String systemMessage = """
          You are a helpful financial assistant. Your job is to build personalized investment portfolios.
          Always respond with specific investment assets (e.g., stock tickers like AAPL, MSFT, or ETFs like VTI, QQQ, etc.), their percentage allocation, and a short reason for each.
          Also include how often the user should invest and how much based on their budget.
          Make sure the total adds to 100%%.
          """;          
          //String systemMessage = "You are a helpful financial assistant." + "Your job is to build personalized investment portfolios";
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

  public String generateGroceryListFromMeal(String mealName, DietaryRestrictions dietaryRestrictions) {
    try {
        // Build dietary restrictions string for the prompt
        StringBuilder dietaryInfo = new StringBuilder();
        boolean hasRestrictions = false;

        if (dietaryRestrictions != null) {
            if (dietaryRestrictions.isVegan()) {
                dietaryInfo.append("- Vegan: No animal products including meat, dairy, eggs, honey\n");
                hasRestrictions = true;
            } else if (dietaryRestrictions.isVegetarian()) {
                dietaryInfo.append("- Vegetarian: No meat, fish, or poultry\n");
                hasRestrictions = true;
            }

            if (dietaryRestrictions.isLactoseIntolerant() || dietaryRestrictions.isDairyFree()) {
                dietaryInfo.append("- No dairy products\n");
                hasRestrictions = true;
            }

            if (dietaryRestrictions.isGlutenFree()) {
                dietaryInfo.append("- Gluten-free: No wheat, barley, rye\n");
                hasRestrictions = true;
            }

            if (dietaryRestrictions.isKosher()) {
                dietaryInfo.append("- Kosher: No pork, shellfish, meat and dairy together\n");
                hasRestrictions = true;
            }

            if (dietaryRestrictions.isNutFree()) {
                dietaryInfo.append("- No nuts\n");
                hasRestrictions = true;
            }
        }

        String dietaryPrefix = hasRestrictions ?
            "User has the following dietary restrictions:\n" + dietaryInfo.toString() :
            "User has no specific dietary restrictions.";

        String systemMessage = """
            You are a smart recipe assistant that helps users with dietary restrictions.

            %s

            When given a meal name, analyze if it can be made with these dietary restrictions.

            If the meal cannot be made with these dietary restrictions, respond with a JSON object:
            {"incompatible": true, "reason": "explanation of why the meal can't be made with these restrictions"}

            If the meal requires substitutions to meet dietary restrictions, respond with a JSON object:
            {"modifications": "explanation of the modifications made", "items": [array of grocery items]}

            If the meal can be made as-is with these dietary restrictions, respond with a JSON array of grocery items.

            Each grocery item should include:
            - name (string): The name of the ingredient, in PROPER CASE
            - quantity (int): Number of the item to buy at the store
            - notes (string): Optional measurement info or special instructions

            Example grocery item: {"name": "Chicken breast", "quantity": 1, "notes": "1 pound"}

            All grocery items in a grocery list should be in a JSON array format, and separated by commas.

            Example: [{"name": "Eggs", "quantity": 6}, {"name": "Milk", "quantity": 1}]

            Respond with ONLY the JSON with no additional text, explanation, or formatting.
            """.formatted(dietaryPrefix);

        ResponseCreateParams params = ResponseCreateParams.builder()
            .input(mealName)
            .instructions(systemMessage)
            .model(ChatModel.GPT_4O_MINI)
            .build();

        Response response = openAIClient.responses().create(params);

        // Get response as text
        ResponseOutputText rot = response.output().get(0).message().get().content().get(0).asOutputText();

        // Print the raw JSON response
        String jsonResponse = rot.text();

        return jsonResponse;

    } catch (OpenAIException e) {
        e.printStackTrace();
        return "{\"incompatible\": true, \"reason\": \"Service Error: Unable to process the meal request\"}";
    } catch (Exception e) {
        e.printStackTrace();
        return "{\"incompatible\": true, \"reason\": \"Service Error: " + e.getMessage() + "\"}";
    }
  }

  // The original method that the controller calls
  public String generateGroceryListFromMeal(String mealName, String username) throws Exception {
    try {
        // Get the dietary restrictions for this user
        DietaryRestrictions dietaryRestrictions = null;
        try {
            // Assuming dietaryRestrictionsService is autowired
            dietaryRestrictions = dietaryRestrictionsService.getDietaryRestrictions(username);
        } catch (Exception e) {
            // If we can't get dietary restrictions, create default ones (all false)
            dietaryRestrictions = new DietaryRestrictions();
            dietaryRestrictions.setUsername(username);
        }

        // Get raw JSON response from OpenAI with dietary restrictions
        return generateGroceryListFromMeal(mealName, dietaryRestrictions);
    } catch (Exception e) {
        e.printStackTrace();
        throw new Exception("Failed to generate grocery list: " + e.getMessage(), e);
    }
  }
}
