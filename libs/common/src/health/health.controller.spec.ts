import { Test } from '@nestjs/testing';
import { HealthController } from './health.controller';

describe('HealthController', () => {
  it('returns an ok status', async () => {
    const module = await Test.createTestingModule({
      controllers: [HealthController],
    }).compile();

    const controller = module.get(HealthController);

    expect(controller.health()).toEqual({ status: 'ok' });
  });
});
