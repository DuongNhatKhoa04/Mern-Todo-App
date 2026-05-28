import express from "express"
import mongoose from "mongoose"
import cors from "cors"
import dotenv from "dotenv"

import logger from "./utils/logger.js"
import httpLogger from "./middleware/httpLogger.js"
import userRouter from "./routes/userRoute.js"
import taskRouter from "./routes/taskRoute.js"
import forgotPasswordRouter from "./routes/forgotPassword.js"

//app config
dotenv.config()
const app = express()
const port = process.env.PORT || 8001
mongoose.set('strictQuery', true);

//middlewares
app.use(express.json())
app.use(cors())
app.use(httpLogger)

//db config
mongoose.connect(process.env.MONGO_URI, {
    useNewUrlParser: true,
}, (err) => {
    if (err) {
        logger.error("MongoDB connection failed", { error: err.message })
    } else {
        logger.info("MongoDB connected")
    }
})

//api endpoints
app.use("/api/user", userRouter)
app.use("/api/task", taskRouter)
app.use("/api/forgotPassword", forgotPasswordRouter)

//listen
app.listen(port, () => logger.info(`Server listening on port ${port}`))