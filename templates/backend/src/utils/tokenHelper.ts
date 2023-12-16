/* eslint-disable no-param-reassign */
import { Response } from 'express';
import * as jwt from 'jsonwebtoken';
import { IUserModel } from '../models/user.model';
const cookieToken = async (user: IUserModel, res: Response) => {
  try {
    const accessToken = user.getJwtAccessToken();
    const refreshToken = user.getJwtRefreshToken();

    user.tokens = user.tokens || [];
    user.tokens.push(accessToken, refreshToken);

    await user.save();

    // Create a response object excluding sensitive information
    const userResponse = {
      ...user,
      password: undefined,
      tokens: undefined,
    };

    const cookieTime = parseInt(process.env.COOKIE_TIME || '7', 10); // Default to 7 days
    const options = {
      expires: new Date(Date.now() + cookieTime * 86400000), // 86400000 ms in a day
      httpOnly: true,
    };

    res.status(200).cookie('accessToken', accessToken, options).json({
      success: true,
      accessToken,
      refreshToken,
      user: userResponse,
    });
  } catch (err) {
    const errorMessage = err instanceof Error ? err.message : 'Unknown error';
    res.status(500).json({
      success: false,
      message: 'Error in creating JWT token',
      error: errorMessage,
    });
  }
};

const veryfyJwtToken = (token: string) => {
  try {
    const JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET;
    if (!JWT_ACCESS_SECRET) {
      throw new Error('JWT_ACCESS_SECRET is not defined');
    }

    return {
      isValid: true,
      decoded: jwt.verify(token, JWT_ACCESS_SECRET),
    };
  } catch (err) {
    const errorMessage = err instanceof Error ? err.message : 'Unknown error';
    return {
      isValid: false,
      error: errorMessage,
    };
  }
};
export { cookieToken, veryfyJwtToken };
