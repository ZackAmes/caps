import { RpcProvider } from 'starknet';
import { dojoConfig } from './config';

export const provider = new RpcProvider({ nodeUrl: dojoConfig.rpcUrl });
export const ACTIONS = dojoConfig.contracts.actions;
