import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { sepolia } from "wagmi/chains";

export const config = getDefaultConfig({
  appName: "AIVault",
  projectId: "a2c929670a47c3e50791389a3b9efc9c",
  chains: [sepolia],
  ssr: true,
});

// a2c929670a47c3e50791389a3b9efc9c - My Project ID
