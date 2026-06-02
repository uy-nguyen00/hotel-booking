import { AuthGuard } from '@nestjs/passport';
import { ExecutionContext } from '@nestjs/common';

export class JwtAuthGuard extends AuthGuard('jwt') {
  getRequest(context: ExecutionContext) {
    return context.getType() === 'rpc'
      ? context.switchToRpc().getData()
      : context.switchToHttp().getRequest();
  }
}
