# Gemma 4 — Local Inference Evaluation

**Production date**: 2026-04-13
**Producing agent**: Claude Opus 4.6 (researcher)
**Context**: Evaluating Gemma 4 for local inference on GMKtec K12 (Ryzen 9 7945HX, Radeon 780M iGPU, 64GB DDR5)
**License**: Apache 2.0 (fully commercial)

---

## Model Family (released 2026-04-02)

| Model | Architecture | Effective Params | Active Params | VRAM (Q4) | Modalities |
|-------|-------------|-----------------|---------------|-----------|------------|
| E2B | Dense | 2.3B | 2.3B | ~4 GB | Text, Image, Audio |
| E4B | Dense | 4.5B | 4.5B | ~6 GB | Text, Image, Audio |
| 26B | MoE | 26B total | 3.8B | ~14 GB | Text, Image |
| 31B | Dense | 31B | 31B | ~20 GB | Text, Image |

## Benchmarks

| Benchmark | 26B MoE | 31B Dense | Notes |
|-----------|---------|-----------|-------|
| AIME 2026 (math) | 88.3% | 89.2% | |
| LiveCodeBench v6 | 77.1% | 80.0% | |
| GPQA Diamond (science) | 82.3% | 84.3% | |
| τ2-bench (agentic) | — | 86.4% | |
| Arena ELO (open models) | #6 (1441) | #3 (1452) | |

## Hardware Fit: K12 Mini PC

### Recommended: 26B MoE

- **Why**: Only 3.8B active parameters per inference = fast token generation, but draws on 26B total for quality
- **VRAM**: ~14GB at Q4 — fits at 16GB iGPU allocation, comfortable at 32GB
- **Tradeoff**: Benchmarks within 1-3% of the 31B dense at ~1/8 the active compute

### Alternative: 31B Dense

- **VRAM**: ~20GB at Q4 — requires 32GB iGPU allocation (leaves 32GB system RAM)
- **Better for**: Tasks where every benchmark point matters
- **Slower**: 8x more active params = proportionally slower on iGPU

### Lightweight: E4B

- **VRAM**: ~6GB — runs on any config
- **Use case**: Quick local inference, testing, audio input support

## AMD Compatibility

- AMD provides Day 0 support for Gemma 4 on Ryzen AI processors
- Ollama with Vulkan backend is the recommended path for iGPU
- ROCm does NOT support iGPUs — use Vulkan

## Setup

```bash
# Install ollama (if not present)
curl -fsSL https://ollama.com/install.sh | sh

# Pull recommended model
ollama pull gemma4:26b

# Or for the dense model (needs 32GB VRAM)
ollama pull gemma4:31b
```

## Key Takeaway

The 26B MoE model is the sweet spot for iGPU inference — near-flagship quality at a fraction of the compute cost. At 16GB VRAM allocation it fits; at 32GB it's comfortable with room for context.

---

## Sources

- [Gemma 4 — Google Blog](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/)
- [Gemma 4 — Google DeepMind](https://deepmind.google/models/gemma/gemma-4/)
- [Day 0 Support for Gemma 4 on AMD](https://www.amd.com/en/developer/resources/technical-articles/2026/day-0-support-for-gemma-4-on-amd-processors-and-gpus.html)
- [Gemma 4 on Ollama](https://ollama.com/library/gemma4)
- [All 4 Model Sizes Compared — DEV Community](https://dev.to/purpledoubled/how-to-run-googles-gemma-4-locally-with-ollama-all-4-model-sizes-compared-2pbh)
