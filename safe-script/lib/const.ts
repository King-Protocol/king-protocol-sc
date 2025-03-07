import "dotenv/config";

export const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
if (!PRIVATE_KEY) throw new Error("PRIVATE_KEY not found in .env");

export const MAINNET_RPC = process.env.MAINNET_RPC || "";
if (!MAINNET_RPC) throw new Error("MAINNET_RPC not found in .env");

export const KING_SAFE_WALLET = "0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5";

export const KING_PROTOCOL_PROXY = "0x8F08B70456eb22f6109F57b8fafE862ED28E6040";
export const KING_PROTOCOL_CORE_IMPL =
  "0x1cB489ef513E1Cc35C4657c91853A2E6fF1957dE";
// This contract was used to update LRT2 name to KING. Please, don't use this contact anywhere else 
export const KING_PROTOCOL_DUMMY_IMPL =
  "0x8E029cEDC7Daf4d9cFFe56AC6771dE266F3CCAdc";

export const KING_PRICE_PROVIDER = "0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3";
