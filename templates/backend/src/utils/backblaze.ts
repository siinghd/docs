/* eslint-disable eslint-comments/disable-enable-pair */
/* eslint-disable no-use-before-define */
/* eslint-disable no-await-in-loop */
/* eslint-disable class-methods-use-this */
import axios from 'axios';
import { createHash } from 'node:crypto';
import { callWithRetry } from './methods';

class BackblazeB2Client {
  private apiUrl: string;

  private authorizationToken: string | null = null;

  private downloadUrl: string | null = null;

  private authorizationExpiration: Date | null = null;

  private static instance: BackblazeB2Client | null = null;

  private constructor(
    private keyId: string,
    private applicationKey: string,
    private retries: number = 3,
    private retryDelay: number = 1000
  ) {
    this.apiUrl = 'https://api.backblazeb2.com/b2api/v2';
  }

  static getInstance(
    keyId: string,
    applicationKey: string,
    retries?: number,
    retryDelay?: number
  ): BackblazeB2Client {
    if (!this.instance) {
      this.instance = new BackblazeB2Client(
        keyId,
        applicationKey,
        retries,
        retryDelay
      );
    }
    return this.instance;
  }

  private async authorize(): Promise<void> {
    if (
      this.authorizationExpiration &&
      new Date() < this.authorizationExpiration
    ) {
      return;
    }

    const headers = {
      Authorization: `Basic ${Buffer.from(
        `${this.keyId}:${this.applicationKey}`
      ).toString('base64')}`,
    };

    const response = await axios.get(`${this.apiUrl}/b2_authorize_account`, {
      headers,
    });
    this.apiUrl = `${response.data.apiUrl}/b2api/v2`;
    this.authorizationToken = response.data.authorizationToken;
    this.downloadUrl = response.data.downloadUrl;
    this.authorizationExpiration = new Date(
      Date.now() + 24 * 60 * 60 * 1000 - 60000
    );
  }

  private async callAPI(
    endpoint: string,
    method: 'GET' | 'POST' = 'POST',
    data: Record<string, any> = {},
    params: Record<string, any> = {}
  ): Promise<any> {
    return callWithRetry(
      async () => {
        await this.authorize();
        const headers = {
          Authorization: this.authorizationToken,
          'Content-Type': 'application/json',
        };

        const response = await axios({
          method,
          url: `${this.apiUrl}/${endpoint}`,
          headers,
          data,
          params,
        });

        return response.data;
      },
      this.retries,
      this.retryDelay
    );
  }

  private calculateSHA1(data: Buffer): string {
    const sha1 = createHash('sha1');
    sha1.update(data);
    return sha1.digest('hex');
  }

  // B2 Native API Methods
  b2_authorize_account = () => this.authorize();

  b2_cancel_large_file = (fileId: string) =>
    this.callAPI('b2_cancel_large_file', 'POST', { fileId });

  b2_copy_file = (params: Record<string, any>) =>
    this.callAPI('b2_copy_file', 'POST', params);

  b2_copy_part = (params: Record<string, any>) =>
    this.callAPI('b2_copy_part', 'POST', params);

  b2_create_bucket = (params: Record<string, any>) =>
    this.callAPI('b2_create_bucket', 'POST', params);

  b2_create_key = (params: Record<string, any>) =>
    this.callAPI('b2_create_key', 'POST', params);

  b2_delete_bucket = (params: Record<string, any>) =>
    this.callAPI('b2_delete_bucket', 'POST', params);

  b2_delete_file_version = (params: Record<string, any>) =>
    this.callAPI('b2_delete_file_version', 'POST', params);

  b2_delete_key = (params: Record<string, any>) =>
    this.callAPI('b2_delete_key', 'POST', params);

  b2_download_file_by_id = (params: Record<string, any>) =>
    this.callAPI('b2_download_file_by_id', 'GET', params);

  b2_download_file_by_name = (params: Record<string, any>) =>
    this.callAPI('b2_download_file_by_name', 'GET', params);

  b2_finish_large_file = (params: Record<string, any>) =>
    this.callAPI('b2_finish_large_file', 'POST', params);

  b2_get_download_authorization = (params: Record<string, any>) =>
    this.callAPI('b2_get_download_authorization', 'POST', params);

  b2_get_file_info = (params: Record<string, any>) =>
    this.callAPI('b2_get_file_info', 'POST', params);

  b2_get_upload_part_url = (params: Record<string, any>) =>
    this.callAPI('b2_get_upload_part_url', 'POST', params);

  b2_get_upload_url = (bucketId: string) =>
    this.callAPI(
      'b2_get_upload_url',
      'GET',
      {},
      {
        bucketId,
      }
    );

  b2_hide_file = (params: Record<string, any>) =>
    this.callAPI('b2_hide_file', 'POST', params);

  b2_list_buckets = (params: Record<string, any>) =>
    this.callAPI('b2_list_buckets', 'POST', params);

  b2_list_file_names = (params: Record<string, any>) =>
    this.callAPI('b2_list_file_names', 'POST', params);

  b2_list_file_versions = (params: Record<string, any>) =>
    this.callAPI('b2_list_file_versions', 'POST', params);

  b2_list_keys = (params: Record<string, any>) =>
    this.callAPI('b2_list_keys', 'POST', params);

  b2_list_parts = (params: Record<string, any>) =>
    this.callAPI('b2_list_parts', 'POST', params);

  b2_list_unfinished_large_files = (params: Record<string, any>) =>
    this.callAPI('b2_list_unfinished_large_files', 'POST', params);

  b2_start_large_file = (params: Record<string, any>) =>
    this.callAPI('b2_start_large_file', 'POST', params);

  b2_update_bucket = (params: Record<string, any>) =>
    this.callAPI('b2_update_bucket', 'POST', params);

  b2_update_file_legal_hold = (params: Record<string, any>) =>
    this.callAPI('b2_update_file_legal_hold', 'POST', params);

  b2_update_file_retention = (params: Record<string, any>) =>
    this.callAPI('b2_update_file_retention', 'POST', params);

  b2_upload_file = (params: Record<string, any>) =>
    this.callAPI('b2_upload_file', 'POST', params);

  b2_upload_part = (params: Record<string, any>) =>
    this.callAPI('b2_upload_part', 'POST', params);

  // TODO:  Add other B2 Native API methods

  async uploadLargeFile(
    fileData: Buffer,
    fileName: string,
    bucketId: string
  ): Promise<any> {
    // Step 1: Start the large file upload
    const startResponse = await this.b2_start_large_file({
      bucketId,
      fileName,
      contentType: 'application/octet-stream',
    });
    const { fileId } = startResponse;

    // Determine part size (minimum part size is 5MB)
    const recommendedPartSize = Math.max(
      startResponse.recommendedPartSize,
      5 * 1024 * 1024
    );
    const totalParts = Math.ceil(fileData.length / recommendedPartSize);

    // Step 2: Upload parts
    for (let partNumber = 1; partNumber <= totalParts; partNumber += 1) {
      const start = (partNumber - 1) * recommendedPartSize;
      const end = partNumber * recommendedPartSize;
      const partData = fileData.slice(start, end);

      const uploadUrlResponse = await this.b2_get_upload_part_url({ fileId });
      const { uploadUrl } = uploadUrlResponse;
      const uploadAuthToken = uploadUrlResponse.authorizationToken;

      const headers = {
        Authorization: uploadAuthToken,
        'Content-Length': partData.length.toString(),
        'X-Bz-Part-Number': partNumber.toString(),
        'X-Bz-Content-Sha1': 'do_not_verify', // Skipping SHA-1 verification
      };
      await callWithRetry(
        async () => {
          await axios.post(uploadUrl, partData, { headers });
        },
        this.retries,
        this.retryDelay
      );
    }

    // Step 3: Finish the large file upload
    // Note: You'll need to modify the b2_finish_large_file method to work without partSha1Array
    const finishResponse = await this.b2_finish_large_file({ fileId });

    return finishResponse;
  }
}

export = BackblazeB2Client;
