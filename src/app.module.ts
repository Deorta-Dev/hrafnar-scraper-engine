import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { SessionService } from './session/session.service';
import { ExecuteService } from './execute/execute.service';
import { ExecutionEngine } from './engine/execution.engine';

@Module({
  controllers: [AppController],
  providers: [
    SessionService,
    ExecuteService,
    ExecutionEngine,
  ],
})
export class AppModule {}
