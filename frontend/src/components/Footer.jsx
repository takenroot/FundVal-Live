import { useState, useEffect } from 'react';
import { Layout, Space, Typography, theme } from 'antd';
import { GithubOutlined } from '@ant-design/icons';
import { healthCheck } from '../api';

const { Footer: AntFooter } = Layout;
const { Link, Text } = Typography;

const Footer = () => {
  const { token } = theme.useToken();
  const [version, setVersion] = useState('');

  useEffect(() => {
    healthCheck()
      .then((res) => setVersion(res.data.version || ''))
      .catch(() => {});
  }, []);

  return (
    <AntFooter
      style={{
        textAlign: 'center',
        padding: '16px 24px',
        background: token.colorFillAlter,
        borderTop: `1px solid ${token.colorBorderSecondary}`,
      }}
    >
      <Space direction="vertical" size="small" style={{ width: '100%' }}>
        <Text type="secondary" style={{ fontSize: 13 }}>
          © 2024-2026 Fundval. Licensed under{' '}
          <Link
            href="https://github.com/Ye-Yu-Mo/FundVal-Live/blob/main/LICENSE"
            target="_blank"
            rel="noopener noreferrer"
          >
            AGPL-3.0
          </Link>
          .
        </Text>
        <Space size="middle">
          <Link
            href="https://github.com/Ye-Yu-Mo/FundVal-Live"
            target="_blank"
            rel="noopener noreferrer"
          >
            <Space>
              <GithubOutlined style={{ fontSize: 16 }} />
              <span>GitHub</span>
            </Space>
          </Link>
          <Link
            href="https://github.com/Ye-Yu-Mo/FundVal-Live/stargazers"
            target="_blank"
            rel="noopener noreferrer"
          >
            <span>⭐ Star</span>
          </Link>
          {version && (
            <Text type="secondary" style={{ fontSize: 12 }}>
              v{version}
            </Text>
          )}
        </Space>
      </Space>
    </AntFooter>
  );
};

export default Footer;
