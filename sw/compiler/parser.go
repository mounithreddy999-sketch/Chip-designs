package main

import (
	"encoding/json"
	"os"
)

type Model struct {
	Name   string  `json:"name"`
	Layers []Layer `json:"layers"`
}

type Layer struct {
	Type     string `json:"type"`      // "Linear", "ReLU"
	InputDim int    `json:"in_dim"`
	OutDim   int    `json:"out_dim"`
	Weights  []int  `json:"weights,omitempty"` // Flat array of size InputDim * OutDim
	Biases   []int  `json:"biases,omitempty"`  // Flat array of size OutDim
}

func ParseModel(path string) (*Model, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var model Model
	if err := json.Unmarshal(data, &model); err != nil {
		return nil, err
	}

	return &model, nil
}
