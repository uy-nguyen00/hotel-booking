import { ExecutionContext } from '@nestjs/common';
import { JwtAuthGuard } from './jwt-auth-guard';

describe('JwtAuthGuard', () => {
  it('uses RPC payload as Passport request data', () => {
    const rpcData = { Authentication: 'token' };
    const httpRequest = {};
    const context = {
      getType: () => 'rpc',
      switchToHttp: () => ({
        getRequest: () => httpRequest,
      }),
      switchToRpc: () => ({
        getData: () => rpcData,
      }),
    } as ExecutionContext;

    expect((new JwtAuthGuard() as any).getRequest(context)).toBe(rpcData);
  });
});
