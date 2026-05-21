import sequelize from './shared/database/database.js'
import { usersRouter } from './users/router.js'
import express from 'express'

const app = express()
const PORT = Number(process.env.PORT) || 8000

// Sequelize sync (recreates schema on boot, matches original behaviour).
// In a real production setup this would be replaced by versioned migrations.
sequelize.sync({ force: true }).then(() => console.log('db is ready'))

app.use(express.json())

// Liveness/readiness probe endpoint used by Docker HEALTHCHECK and
// Kubernetes liveness/readiness probes. Kept dependency-free so it
// returns 200 even if downstream resources are degraded; the DB layer
// is exercised by the actual /api/users endpoints.
app.get('/health', (_req, res) => {
    res.status(200).json({
        status: 'ok',
        uptime: process.uptime(),
        timestamp: new Date().toISOString(),
    })
})

app.use('/api/users', usersRouter)

const server = app.listen(PORT, () => {
    console.log('Server running on port', PORT)
})

export { app, server }
