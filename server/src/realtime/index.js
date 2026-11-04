import { Server } from 'socket.io';
import { verifyAccessToken } from '../services/tokens.js';
import { User } from '../models/index.js';

/**
 * Realtime hub. Routes/services call `emit(userId, event, payload)`; sockets only
 * receive. Events are per-process: with several API instances, a socket sees the
 * events caused on its own instance (see docs/API.md, "Scaling").
 */
export function createRealtimeHub({ config, logger }) {
  let io = null;
  const origins = config.corsOrigins.includes('*') ? true : config.corsOrigins;

  return {
    attach(httpServer) {
      io = new Server(httpServer, { path: '/socket.io', cors: { origin: origins }, serveClient: false });
      io.use(async (socket, next) => {
        try {
          const token = socket.handshake.auth?.token;
          if (typeof token !== 'string') throw new Error('no token');
          const userId = verifyAccessToken(config, token);
          if (!(await User.exists({ _id: userId }))) throw new Error('no user');
          socket.data.userId = userId;
          next();
        } catch {
          next(new Error('unauthorized'));
        }
      });
      io.on('connection', (socket) => {
        socket.join(`user:${socket.data.userId}`);
        logger.debug('socket connected', { userId: socket.data.userId });
      });
    },
    emit(userId, event, payload) {
      io?.to(`user:${userId}`).emit(event, payload);
    },
    disconnectUser(userId) {
      io?.in(`user:${userId}`).disconnectSockets(true);
    },
    async close() {
      if (io) await new Promise((resolve) => io.close(resolve));
      io = null;
    },
  };
}
