const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  const user = await prisma.user.create({
    data: {
      fullName: 'Test User',
      email: 'test@example.com',
      password: 'test1234', // In production, hash this!
    },
  });

  console.log('✅ Created user:');
  console.log(user);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
