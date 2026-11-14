# Compressed swap in RAM.
{ ... }:

{
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
