import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    logger: ['log', 'warn', 'error', 'debug'],
  });

  // Global validation pipe - strips unknown properties and validates DTOs
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: false,
      transform: true,
    }),
  );

  // CORS for local development
  app.enableCors();

  const port = process.env.PORT ?? 3000;
  await app.listen(port);

  const logger = new Logger('Bootstrap');
  logger.log(`🚀 Headless Engine running on: http://localhost:${port}`);
  logger.log(`   POST /session          - Create browser session`);
  logger.log(`   POST /execute          - Execute instruction set`);
  logger.log(`   DELETE /session/:id    - Close session`);
}

bootstrap();
