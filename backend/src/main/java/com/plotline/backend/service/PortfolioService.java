package com.plotline.backend.service;

import com.plotline.backend.dto.SavedPortfolio;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;

@Service
public class PortfolioService {
    private final Map<String, SavedPortfolio> savedPortfolios = new HashMap<>();

    public void savePortfolio(String username, SavedPortfolio portfolio) {
        savedPortfolios.put(username, portfolio);
    }

    public SavedPortfolio loadPortfolio(String username) {
        return savedPortfolios.get(username);
    }
}
