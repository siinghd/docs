import { IGetUserAuthInfoRequest } from '../utils/typesAndInterfaces';
import bigPromise from '../middlewares/bigPromise';
import BackBlazeB2 from '../utils/backblaze';

const b2 = BackBlazeB2.getInstance(
  process.env.B2_KEY_ID || '',
  process.env.B2_APP_KEY || ''
);
export const getUploadUrl = bigPromise(
  async (req: IGetUserAuthInfoRequest, res) => {
    const data = await b2.b2_get_upload_url(process.env.B2_BUCKET_ID || '');

    return res.status(200).json({
      success: true,
      ...data,
    });
  }
);
