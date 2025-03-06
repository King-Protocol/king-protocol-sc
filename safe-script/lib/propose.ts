import { ethers } from "ethers";

import SafeApiKit from "@safe-global/api-kit";
import Safe from "@safe-global/protocol-kit";
import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";

import { PRIVATE_KEY, MAINNET_RPC, KING_SAFE_WALLET } from "./const";

const provider = new ethers.providers.JsonRpcProvider(MAINNET_RPC);
const owner = new ethers.Wallet(PRIVATE_KEY, provider);
const apiKit = new SafeApiKit({ chainId: 1n });

export async function propose(
  destination: string,
  data: string,
  value: string,
) {
  const safeTransactionData: MetaTransactionData = {
    to: destination,
    data: data,
    value: value,
  };

  const protocolKitOwner1 = await Safe.init({
    provider: MAINNET_RPC,
    signer: PRIVATE_KEY,
    safeAddress: KING_SAFE_WALLET,
  });

  // Create a Safe transaction with the provided parameters
  const safeTransaction = await protocolKitOwner1.createTransaction({
    transactions: [safeTransactionData],
  });

  // Deterministic hash based on transaction parameters
  const safeTxHash =
    await protocolKitOwner1.getTransactionHash(safeTransaction);
  // Sign transaction to verify that the transaction is coming from owner 1
  const senderSignature = await protocolKitOwner1.signHash(safeTxHash);

  await apiKit.proposeTransaction({
    safeAddress: KING_SAFE_WALLET,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress: owner.address,
    senderSignature: senderSignature.data,
  });

  const pendingTransactions = (
    await apiKit.getPendingTransactions(KING_SAFE_WALLET)
  ).results;
  console.log(pendingTransactions);
}
