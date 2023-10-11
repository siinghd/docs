import mongoose from 'mongoose';

const logSchema: mongoose.Schema = new mongoose.Schema(
  {
    level: {
      type: String,
      required: true,
      trim: true,
    },
    message: {
      type: String,
      required: true,
    },
    hostname: {
      type: String,
      required: true,
    },
    meta: {
      type: mongoose.Schema.Types.Mixed,
    },
  },
  { timestamps: true, collection: 'log' }
);

module.exports = mongoose.model('Log', logSchema);
