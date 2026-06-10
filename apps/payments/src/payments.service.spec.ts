import { ConfigService } from '@nestjs/config';
import { ClientProxy } from '@nestjs/microservices';
import { PaymentsService } from './payments.service';

describe('PaymentsService', () => {
  it('constructs the Stripe client', () => {
    const configService = {
      get: jest.fn().mockReturnValue('sk_test_placeholder'),
    } as unknown as ConfigService;
    const notificationsService = {} as ClientProxy;

    expect(
      () => new PaymentsService(configService, notificationsService),
    ).not.toThrow();
  });
});
