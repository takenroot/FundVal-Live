import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Space, Button, Modal, Form, Input, message } from 'antd';
import {
  AccountBookOutlined,
  SettingOutlined,
  UserOutlined,
  LockOutlined,
  LogoutOutlined,
} from '@ant-design/icons';
import { useAuth } from '../contexts/AuthContext';
import { changePassword } from '../api';

const ProfilePage = () => {
  const navigate = useNavigate();
  const { user, logout } = useAuth();
  const [pwdModal, setPwdModal] = useState(false);
  const [pwdLoading, setPwdLoading] = useState(false);
  const [form] = Form.useForm();

  const handleChangePwd = async (values) => {
    setPwdLoading(true);
    try {
      await changePassword(values.oldPassword, values.newPassword);
      message.success('密码修改成功，请重新登录');
      form.resetFields();
      setPwdModal(false);
      setTimeout(() => logout(), 1500);
    } catch (err) {
      message.error(err.response?.data?.error || '修改失败');
    } finally {
      setPwdLoading(false);
    }
  };

  const items = [
    {
      key: 'accounts',
      icon: <AccountBookOutlined />,
      title: '账户管理',
      desc: '管理我的账户和持仓',
      path: '/dashboard/accounts',
    },
    {
      key: 'settings',
      icon: <SettingOutlined />,
      title: '系统设置',
      desc: '数据源、AI配置、通知渠道',
      path: '/dashboard/settings',
    },
    ...(user?.role === 'admin'
      ? [
          {
            key: 'admin',
            icon: <UserOutlined />,
            title: '用户管理',
            desc: '管理员面板',
            path: '/dashboard/admin',
          },
        ]
      : []),
  ];

  return (
    <Space direction="vertical" style={{ width: '100%' }} size="middle">
      <Card>
        <div style={{ textAlign: 'center', padding: '16px 0' }}>
          <UserOutlined style={{ fontSize: 48, color: '#1890ff', marginBottom: 8 }} />
          <div style={{ fontSize: 18, fontWeight: 'bold' }}>{user?.username}</div>
          <div style={{ color: '#999', fontSize: 13 }}>
            {user?.role === 'admin' ? '管理员' : '用户'}
          </div>
          <Space style={{ marginTop: 16 }}>
            <Button icon={<LockOutlined />} onClick={() => setPwdModal(true)}>
              修改密码
            </Button>
            <Button icon={<LogoutOutlined />} danger onClick={logout}>
              退出登录
            </Button>
          </Space>
        </div>
      </Card>
      {items.map((item) => (
        <Card
          key={item.key}
          hoverable
          onClick={() => navigate(item.path)}
          style={{ cursor: 'pointer' }}
        >
          <Space>
            <span style={{ fontSize: 24, color: '#1890ff' }}>{item.icon}</span>
            <div>
              <div style={{ fontWeight: 500 }}>{item.title}</div>
              <div style={{ fontSize: 12, color: '#999' }}>{item.desc}</div>
            </div>
          </Space>
        </Card>
      ))}

      <Modal
        title="修改密码"
        open={pwdModal}
        onCancel={() => setPwdModal(false)}
        onOk={() => form.submit()}
        confirmLoading={pwdLoading}
        okText="确认修改"
      >
        <Form form={form} layout="vertical" onFinish={handleChangePwd}>
          <Form.Item
            name="oldPassword"
            label="当前密码"
            rules={[{ required: true, message: '请输入当前密码' }]}
          >
            <Input.Password placeholder="输入当前密码" />
          </Form.Item>
          <Form.Item
            name="newPassword"
            label="新密码"
            rules={[
              { required: true, message: '请输入新密码' },
              { min: 8, message: '密码至少 8 位' },
            ]}
          >
            <Input.Password placeholder="输入新密码（至少8位）" />
          </Form.Item>
          <Form.Item
            name="confirmPassword"
            label="确认新密码"
            dependencies={['newPassword']}
            rules={[
              { required: true, message: '请确认新密码' },
              ({ getFieldValue }) => ({
                validator(_, value) {
                  if (!value || getFieldValue('newPassword') === value) return Promise.resolve();
                  return Promise.reject(new Error('两次密码不一致'));
                },
              }),
            ]}
          >
            <Input.Password placeholder="再次输入新密码" />
          </Form.Item>
        </Form>
      </Modal>
    </Space>
  );
};

export default ProfilePage;
