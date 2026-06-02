package main

import (
	"flag"
	"fmt"
	"log"
)

func main() {
	modelPath := flag.String("model", "", "Path to the JSON model file")
	outPath := flag.String("out", "firmware.c", "Output C firmware file path")
	flag.Parse()

	if *modelPath == "" {
		log.Fatal("Error: -model argument is required")
	}

	fmt.Printf("Compiling Neural Network Model: %s\n", *modelPath)

	// 1. Parse the JSON model
	model, err := ParseModel(*modelPath)
	if err != nil {
		log.Fatalf("Failed to parse model: %v", err)
	}
	fmt.Printf("Parsed Model '%s' with %d layers\n", model.Name, len(model.Layers))

	// 2. Map the layers to CGRA instructions
	instructions, err := MapToCGRA(model)
	if err != nil {
		log.Fatalf("Failed to map model to CGRA: %v", err)
	}
	fmt.Printf("Mapped to %d microcode instructions\n", len(instructions))

	// 3. Generate C firmware
	err = GenerateFirmware(model, instructions, *outPath)
	if err != nil {
		log.Fatalf("Failed to generate firmware: %v", err)
	}
	
	fmt.Printf("Successfully generated firmware at: %s\n", *outPath)
}
