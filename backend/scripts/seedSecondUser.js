const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  const user = await prisma.user.create({
    data: {
      fullName: 'Second User',
      email: 'second@example.com',
      password: 'password123' // Not hashed — just for test
    },
  });

  console.log('✅ Created second user:');
  console.log(user);
}

main()
  .catch((e) => console.error(e))
  .finally(() => prisma.$disconnect());
